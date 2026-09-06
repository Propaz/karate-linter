Feature: multibyte byte offsets

    Background:
        * def base = 1

    Scenario: cyrillic before an unbalanced brace
        * def payload = { имя: 'значение'
        Then match base == 1

    Scenario Outline: cyrillic table cells
        Given path '<идентификатор>'

        Examples:
            | идентификатор | лишний |
            | 1             | 2      |
