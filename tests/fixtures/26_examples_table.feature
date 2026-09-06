Feature: examples table problems

    Background:
        * def base = 1

    Scenario Outline: row shorter than header
        Given path '<a>', '<b>'

        Examples:
            | a | b |
            | 1 | 2 |
            | 3 |
            | 4 | 5 | 6 |

    Scenario Outline: duplicate column
        Given path '<id>'

        Examples:
            | id | id |
            | 1  | 2  |

    Scenario Outline: header without data
        Given path '<x>'

        Examples:
            | x |
