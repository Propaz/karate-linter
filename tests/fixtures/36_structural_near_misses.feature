Feature: structural near misses

    The comments and the payload below mention Gherkin keywords on purpose.
    None of them is a second Feature, a stray Examples or a misplaced
    Background, and this file must lint clean.

    Background:
        * def region = 'north'

    # Feature: a comment, not a second feature
    Scenario: keywords inside a comment
        Given path 'health'
        # Examples: mentioned with no table under it
        # Background: mentioned after the first scenario
        Then match region == 'north'

    Scenario: keywords inside a payload
        And request
        """
        Feature: not a feature
        Scenario: keywords inside a payload
        Background: not a background
        Examples:
          | not | a | table |
        """
        Then match region == 'north'

    @smoke
    Scenario Outline: a tagged Examples belongs to this outline
        Given path 'orders/<id>'
        And request
        """
        <root><child>text</child></root>
        """
        Then match region == 'north'

        @data @slow
        Examples:
            | id |
            | 7  |
