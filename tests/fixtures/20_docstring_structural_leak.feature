Feature: structural leak

    Background:
        * def base = 1

    Scenario: payload that mentions gherkin words
        Given request
        """
        {
          "doc": "see Examples: below",
        Examples:
        Scenario Outline: not real
        }
        """
        Then match base == 1
