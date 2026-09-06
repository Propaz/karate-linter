Feature: docstring ok

    Background:
        * def base = 1

    Scenario: closed
        Given request
        """
        { "a": 1 }
        """
        Then match base == 1
