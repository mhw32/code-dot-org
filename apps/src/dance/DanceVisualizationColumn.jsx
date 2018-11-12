import React, {PropTypes} from 'react';
import GameButtons from '../templates/GameButtons';
import ArrowButtons from '../templates/ArrowButtons';
import BelowVisualization from '../templates/BelowVisualization';
import * as gameLabConstants from './constants';
import ProtectedVisualizationDiv from '../templates/ProtectedVisualizationDiv';
import Radium from "radium";
import {connect} from "react-redux";
import i18n from '@cdo/locale';
import queryString from "query-string";
import AgeDialog from "../templates/AgeDialog";

const GAME_WIDTH = gameLabConstants.GAME_WIDTH;
const GAME_HEIGHT = gameLabConstants.GAME_HEIGHT;

const styles = {
  selectStyle: {
    width: '100%',
  }
};

const SongSelector = Radium(class extends React.Component {
  static propTypes = {
    enableSongSelection: PropTypes.bool,
    setSong: PropTypes.func.isRequired,
    selectedSong: PropTypes.string,
    songData: PropTypes.objectOf(PropTypes.object).isRequired,
    filterOff: PropTypes.bool.isRequired
  };

  changeSong = (event) => {
    const songId = event.target.value;
    this.props.setSong(songId);
  };

  render() {
    return (
      <div id="song-selector-wrapper">
        <label><b>{i18n.selectSong()}</b></label>
        <select
          id="song_selector"
          style={styles.selectStyle}
          onChange={this.changeSong}
          value={this.props.selectedSong}
          disabled={!this.props.enableSongSelection}
        >
          {Object.keys(this.props.songData).map((option, i) => (
            (this.props.filterOff || !this.props.songData[option].pg13) &&
              <option key={i} value={option}>{this.props.songData[option].title}</option>

          ))}
        </select>
      </div>
    );
  }
});

class DanceVisualizationColumn extends React.Component {
  static propTypes = {
    showFinishButton: PropTypes.bool.isRequired,
    setSong: PropTypes.func.isRequired,
    selectedSong: PropTypes.string,
    levelIsRunning: PropTypes.bool,
    levelRunIsStarting: PropTypes.bool,
    isShareView: PropTypes.bool.isRequired,
    songData: PropTypes.objectOf(PropTypes.object).isRequired,
    userType: PropTypes.string.isRequired
  };

  state = {
    filterOff: this.setFilterStatus()
  };

  /*
    Turn the song filter off unless there is a teacher override
  */
  turnFilterOff() {
    this.setState({filterOff: queryString.parse(window.location.search).songfilter !== 'on'});
  }

  /*
    The filter defaults to on. If the user is over 13 (identified via account or anon dialog) and
    the teacher override is not activated, filter turns off
   */
  setFilterStatus() {
    // userType - 'teacher', assumed age > 13. 'student', age > 13.
    //            'student_y', age < 13. 'unknown', signed out users
    const signedInOver13 = this.props.userType === 'teacher' || this.props.userType === 'student';
    const teacherOverride = queryString.parse(window.location.search).songfilter === 'on';
    const signedOutAge = sessionStorage.getItem('anon_over13') ? sessionStorage.getItem('anon_over13') === 'true' : false;
    return (signedInOver13 || signedOutAge) && !teacherOverride;
  }

  render() {
    const divDanceStyle = {
      touchAction: 'none',
      width: GAME_WIDTH,
      height: GAME_HEIGHT,
      backgroundColor: '#fff',
      position: 'relative',
      overflow: 'hidden',
    };
    const enableSongSelection = !this.props.levelIsRunning && !this.props.levelRunIsStarting;

    return (
      <div>
        {(sessionStorage.getItem('anon_over13') === null && !this.props.isShareView) &&
          <AgeDialog
            turnOffFilter={this.turnFilterOff.bind(this)}
          />
        }
        <span>
          {!this.props.isShareView &&
            <SongSelector
              enableSongSelection={enableSongSelection}
              setSong={this.props.setSong}
              selectedSong={this.props.selectedSong}
              songData={this.props.songData}
              filterOff={this.state.filterOff}
            />
          }
          <ProtectedVisualizationDiv>
            <div
              id="divDance"
              style={divDanceStyle}
            />
          </ProtectedVisualizationDiv>
          <GameButtons showFinishButton={this.props.showFinishButton}>
            <ArrowButtons />
          </GameButtons>
          <BelowVisualization />
        </span>
      </div>
    );
  }
}

export default connect(state => ({
  isShareView: state.pageConstants.isShareView,
  songData: state.songs.songData,
  selectedSong: state.songs.selectedSong,
  userType: state.progress.userType,
  levelIsRunning: state.runState.isRunning,
  levelRunIsStarting: state.songs.runIsStarting
}))(DanceVisualizationColumn);
