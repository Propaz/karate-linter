Feature: docstring

    Background:
        * def base = 1

    Scenario: unclosed
        Given request
        """
        { "a": 1 }

    Scenario: next
        Given path 'x'
