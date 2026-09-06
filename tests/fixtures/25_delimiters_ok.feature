Feature: delimiters that are fine

    Background:
        * def base = 1

    Scenario: all balanced
        * def payload = { a: 1, b: [2, 3] }
        * def msg = 'a { brace and a [ bracket in a string'
        * def dq = "unclosed { inside double quotes"
        * def esc = 'it\'s { escaped'
        * def url = karate.get('http://example.com/a')
        * def cmt = base // trailing { comment
        * def grouping = (base + 1)
        Then match base == 1
