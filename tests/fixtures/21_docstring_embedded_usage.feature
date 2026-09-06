Feature: variable used only inside a docstring

    Background:
        * def base = 1

    Scenario: embedded expression counts as usage
        * def userId = 42
        Given request
        """
        { "id": "#(userId)" }
        """
        Then match base == 1
