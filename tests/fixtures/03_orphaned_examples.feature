Feature: orphaned

    Background:
        * def base = 1

    Scenario: plain
        Given path 'x'

        Examples:
            | a |
            | 1 |
