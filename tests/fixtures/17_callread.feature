Feature: callread

    Background:
        * def base = 1

    Scenario: missing space
        * def a = callread('x.feature')
        * def b = foocallread('x.feature')
        Then match base == 1
