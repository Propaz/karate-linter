Feature: regex metacharacters in names

    Background:
        * def base = 1

    Scenario Outline: placeholder and header with metachars
        Given path '<a\b>'
        And param dot = '<x.y>'

        Examples:
            | id | a.b |
            | 1  | 2   |
