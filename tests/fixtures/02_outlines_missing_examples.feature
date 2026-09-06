Feature: outlines

    Background:
        * def base = 1

    Scenario Outline: no examples, ended by tag
        Given path '<p>'

    @tagged
    Scenario Outline: no examples, ended by scenario
        Given path '<q>'

    Scenario: plain
        Given path 'x'

    Scenario Outline: no examples at eof
        Given path '<r>'
