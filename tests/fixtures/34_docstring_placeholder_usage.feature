Feature: placeholders that are only ever used inside a docstring

    Background:
        * def timeout = 5

    Scenario: no placeholders at all
        Given path 'health'
        Then match timeout == 5

    Scenario Outline: gherkin substitutes into the docstring body
        Given path 'orders'
        And request
        """
        {
          "region": "<region>",
          "notes": "shipment for <label>"
        }
        """
        Then match timeout == 5

        Examples:
            | region | label   |
            | north  | routine |
