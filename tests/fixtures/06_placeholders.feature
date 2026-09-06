Feature: placeholders

    Background:
        * def base = 1

    Scenario Outline: mismatch
        Given path '<known>'
        And param x = '<missing>'

        Examples:
            | known | extra |
            | a     | b     |
