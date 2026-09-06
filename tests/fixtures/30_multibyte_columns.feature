Feature: multibyte byte offsets

    Background:
        * def base = 1

    Scenario: cyrillic before an unbalanced brace
        * def payload = { имя: 'значение'
        * def широкая = 'кириллическая строка сильно длиннее ста двадцати байт но короче ста двадцати колонок'
        Then match base == 1

    Scenario Outline: cyrillic table cells
        Given path '<идентификатор>'

        Examples:
            | идентификатор | лишний |
            | 1             | 2      |
