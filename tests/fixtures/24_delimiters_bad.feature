Feature: delimiter problems

    Background:
        * def base = 1

    Scenario: unbalanced and unterminated
        * def payload = { a: 1
        * def list = [1, 2
        Given path 'unterminated
        * def deep = { a: [1, 2 }
        Then match base == 1

    Scenario: equal counts but still unbalanced
        * def paired = a) + read(
        * def braces = } + {
        * def instr = 'a ) b' + karate.get(
        Then match base == 1
