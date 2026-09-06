Feature: unbalanced parens

    Background:
        * def base = 1

    Scenario: unclosed calls
        * call read('x.feature'
        * def nested = read(foo(bar)
        * def id = karate.jsonPath(response, '$.id'
        * print karate.pretty(response
        * def v = myJsHelper(base
        And match base == helper(
