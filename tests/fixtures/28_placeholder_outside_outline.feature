Feature: stray placeholders

    Background:
        * def base = 1

    Scenario: copied from an outline
        Given path '<userId>'
        And param q = '<query>'
        Then match base == 1

    Scenario: inline xml must not trip it
        * def body = <root>text</root>
        * def selfclosing = <br/>
        Then match base == 1

    Scenario Outline: real outline is fine
        Given path '<id>'

        Examples:
            | id |
            | 1  |
