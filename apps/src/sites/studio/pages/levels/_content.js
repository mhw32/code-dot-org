import $ from 'jquery';
import React from 'react';
import ReactDom from 'react-dom';
import SafeMarkdown from '@cdo/apps/templates/SafeMarkdown';
import {convertXmlToBlockly} from '@cdo/apps/templates/instructions/utils';

$(document).ready(() => {
  // Render Markdown
  $('.content-level > .markdown-container').each(function() {
    if (!this.dataset.markdown) {
      return;
    }

    var container = this;
    ReactDom.render(
      React.createElement(SafeMarkdown, this.dataset, null),
      this,
      function() {
        convertXmlToBlockly(container);
      }
    );
  });
});
