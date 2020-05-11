# == Schema Information
#
# Table name: contact_rollups_pardot_memory
#
#  id                     :integer          not null, primary key
#  email                  :string(255)      not null
#  pardot_id              :integer
#  pardot_id_updated_at   :datetime
#  data_synced            :json
#  data_synced_at         :datetime
#  data_rejected_at       :datetime
#  data_rejected_reason   :string(255)
#  marked_for_deletion_at :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_contact_rollups_pardot_memory_on_email                   (email) UNIQUE
#  index_contact_rollups_pardot_memory_on_marked_for_deletion_at  (marked_for_deletion_at)
#  index_contact_rollups_pardot_memory_on_pardot_id               (pardot_id) UNIQUE
#

require 'cdo/contact_rollups/v2/pardot'

class ContactRollupsPardotMemory < ApplicationRecord
  self.table_name = 'contact_rollups_pardot_memory'

  # Downloads and saves new email-Pardot ID mappings from Pardot.
  # *Warning:* This method overwrites existing data.
  #
  # @param [Integer] last_id retrieves only Pardot ID greater than this value
  # @param [Integer] limit the maximum number of Pardot prospects to download
  def self.download_pardot_ids(last_id = nil, limit = nil)
    last_id ||= ContactRollupsPardotMemory.maximum(:pardot_id) || 0
    fields = %w(id email)

    PardotV2.retrieve_prospects(last_id, fields, limit) do |prospects|
      current_time = Time.now.utc
      batch = prospects.map do |item|
        {
          email: item['email'],
          pardot_id: item['id'].to_i,
          pardot_id_updated_at: current_time
        }
      end

      import! batch,
        validate: false,
        on_duplicate_key_update: [:pardot_id, :pardot_id_updated_at]
    end
  end

  # Downloads and saves prospect data from Pardot.
  # *Warning:* This method overwrites existing data.
  #
  # @param [Integer] last_id retrieves only Pardot ID greater than this value
  # @param [Integer] limit the maximum number of Pardot prospects to download
  def self.download_pardot_prospects(last_id = nil, limit = nil)
    last_id ||= ContactRollupsPardotMemory.maximum(:pardot_id) || 0

    # Note: db_* fields are sorted alphabetically
    fields = %w(
      id
      email
      db_City
      db_Country
      db_Form_Roles
      db_Forms_Submitted
      db_Has_Teacher_Account
      db_Hour_of_Code_Organizer
      db_Opt_In
      db_Postal_Code
      db_Professional_Learning_Attended
      db_Professional_Learning_Enrolled
      db_Roles
      db_State
    )

    PardotV2.retrieve_prospects(last_id, fields, limit) do |prospects|
      current_time = Time.now.utc
      batch = prospects.map do |item|
        {
          email: item['email'],
          pardot_id: item['id'].to_i,
          pardot_id_updated_at: current_time,
          data_synced: item.except('email', 'id'),
          data_synced_at: current_time
        }
      end

      import! batch,
        validate: false,
        on_duplicate_key_update: [:pardot_id, :pardot_id_updated_at, :data_synced, :data_synced_at]
    end
  end

  def self.download_deleted_pardot_prospects(last_id = nil, limit = nil)
    PardotV2.retrieve_prospects(last_id,  %w(id email), limit, true) do |deleted_prospects|
      current_time = Time.now.utc
      batch = deleted_prospects.map do |item|
        {
          email: item['email'],
          data_rejected_at: current_time,
          data_rejected_reason: PardotHelpers::ERROR_PROSPECT_DELETED_FROM_PARDOT
        }
      end

      import! batch,
        validate: false,
        on_duplicate_key_update: [:data_rejected_at, :data_rejected_reason]
    end
  end

  def self.create_new_pardot_prospects
    # Adds contacts to a batch and then sends batch requests to create new Pardot prospects.
    # Requests may not be sent immediately until batch size is big enough.
    pardot_writer = PardotV2.new
    ActiveRecord::Base.connection.exec_query(query_new_contacts).each do |record|
      data = JSON.parse(record['data']).deep_symbolize_keys
      submissions, errors = pardot_writer.batch_create_prospects record['email'], data
      save_sync_results(submissions, errors, Time.now.utc) if submissions.present?
    end

    # There could be prospects left in the batch because batch size is not yet big enough
    # to trigger a Pardot request. Sends the remaining of the batch to Pardot now.
    submissions, errors = pardot_writer.batch_create_remaining_prospects
    save_sync_results(submissions, errors, Time.now.utc) if submissions.present?
  end

  def self.update_pardot_prospects
    pardot_writer = PardotV2.new
    ActiveRecord::Base.connection.exec_query(query_updated_contacts).each do |record|
      # If pardot_id has changed since the last data sync, we should assume that
      # Pardot prospect data is currently empty and re-sync all contact data.
      old_prospect_data =
        record['pardot_id_changed'] ?
          {} :
          JSON.parse(record['data_synced'] || '{}').deep_symbolize_keys
      new_contact_data = JSON.parse(record['data']).deep_symbolize_keys

      submissions, errors = pardot_writer.batch_update_prospects(
        record['email'],
        record['pardot_id'],
        old_prospect_data,
        new_contact_data
      )
      save_sync_results(submissions, errors, Time.now.utc) if submissions.present?
    end

    submissions, errors = pardot_writer.batch_update_remaining_prospects
    save_sync_results(submissions, errors, Time.now.utc) if submissions.present?
  end

  def self.query_new_contacts
    # New contacts are the ones exist in the production database but not in Pardot
    # (i.e., no valid Pardot IDs in contact_rollups_pardot_memory.)
    # In addition, they must not be previously rejected by Pardot as invalid emails
    # or have been deleted by someone in Pardot.
    <<-SQL.squish
      SELECT processed.email, processed.data
      FROM contact_rollups_processed AS processed
      LEFT OUTER JOIN contact_rollups_pardot_memory AS pardot
        ON processed.email = pardot.email
      WHERE pardot.pardot_id IS NULL
        AND NOT (pardot.data_rejected_reason <=> '#{PardotHelpers::ERROR_INVALID_EMAIL}')
        AND NOT (pardot.data_rejected_reason <=> '#{PardotHelpers::ERROR_PROSPECT_DELETED_FROM_PARDOT}')
    SQL
  end

  def self.query_updated_contacts
    # Updated contacts are contacts that exist in both the production database and Pardot
    # (have valid Pardot IDs). However, their content or Pardot ID mappings have changed since the
    # last sync.
    # We explicitly exclude contacts that have been deleted from Pardot,
    # as attempting to update a prospect that has been deleted from Pardot
    # will resuscitate it as an active prospect.
    <<-SQL.squish
      SELECT
        processed.email, processed.data,
        pardot.pardot_id, pardot.data_synced,
        COALESCE(pardot.pardot_id_updated_at > pardot.data_synced_at, FALSE) AS pardot_id_changed
      FROM contact_rollups_processed AS processed
      INNER JOIN contact_rollups_pardot_memory AS pardot
        ON processed.email = pardot.email
      WHERE pardot.pardot_id IS NOT NULL
        AND (
          (pardot.data_synced_at IS NULL)
          OR (processed.data->>'$.updated_at' > pardot.data_synced_at)
          OR (pardot.pardot_id_updated_at > pardot.data_synced_at)
        )
        AND NOT (pardot.data_rejected_reason <=> '#{PardotHelpers::ERROR_PROSPECT_DELETED_FROM_PARDOT}')
    SQL
  end

  # TODO: sync deleted contacts

  # Saves sync results to database.
  # @param [Array<Hash>] submissions an array of prospects that were synced/submitted to Pardot
  # @param [Array<Hash>] errors an array of hashes, each containing an index and an error message
  #   of a rejected prospect. Rejected prospects are a subset of all prospects submitted to Pardot.
  # @param [Time] submitted_time time when submissions were sent to Pardot
  def self.save_sync_results(submissions, errors, submitted_time)
    rejected_indexes = Set.new errors.pluck(:prospect_index)
    accepted_submissions = submissions.reject.with_index do |_, index|
      rejected_indexes.include? index
    end

    rejected_submissions = errors.map do |item|
      submissions[item[:prospect_index]].merge(error_msg: item[:error_msg])
    end

    save_accepted_submissions accepted_submissions, submitted_time
    save_rejected_submissions rejected_submissions, submitted_time
  end

  def self.save_accepted_submissions(submissions, submitted_time)
    emails_and_data = submissions.map do |item|
      {
        email: item[:email],
        data_synced: item.except(:email, :id),
        data_synced_at: submitted_time
      }
    end

    import! emails_and_data,
      validate: false,
      on_duplicate_key_update: [:data_synced, :data_synced_at]
  end

  def self.save_rejected_submissions(submissions, submitted_time)
    emails_and_errors = submissions.map do |item|
      {
        email: item[:email],
        data_rejected_reason: item[:error_msg],
        data_rejected_at: submitted_time
      }
    end

    import! emails_and_errors,
      validate: false,
      on_duplicate_key_update: [:data_rejected_reason, :data_rejected_at]
  end
end
