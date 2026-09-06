Feature: clean file

    Background:
        * def base = 1

    Scenario: uses base
        Given path 'x'
        Then match base == 1

    Scenario Outline: outline
        Given path '<id>'

        Examples:
            | id |
            | 1  |
