import PropTypes from 'prop-types';
import React from 'react';
import ChoiceResponses from './choice_responses.jsx';

export default class MatrixChoiceResponses extends React.Component {
  static propTypes = {
    answer: PropTypes.object.isRequired,
    question: PropTypes.object.isRequired,
    section: PropTypes.string.isRequired,
    questionId: PropTypes.string.isRequired
  };

  render() {
    const {section, answer, question, questionId} = this.props;

    return (
      <div>
        {Object.keys(question['rows']).map(innerQuestionId => {
          const innerAnswer = answer[innerQuestionId];
          const numRespondents = answer.num_respondents;
          let possibleAnswersMap = question['columns'];
          let parsedQuestionName = `${question['title']} -> ${
            question['rows'][innerQuestionId]
          }`;
          return (
            <ChoiceResponses
              perFacilitator={section === 'facilitator'}
              numRespondents={numRespondents}
              question={parsedQuestionName}
              answers={innerAnswer}
              possibleAnswers={Object.keys(possibleAnswersMap)}
              possibleAnswersMap={possibleAnswersMap}
              key={`${questionId}-${innerQuestionId}`}
              answerType={'singleSelect'}
            />
          );
        })}
      </div>
    );
  }
}
