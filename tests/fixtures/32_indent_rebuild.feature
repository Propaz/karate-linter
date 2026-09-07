Feature: indentation is rebuilt by the plugin, not by =
Free text under Feature, wrongly at column 0.
        A second description line, wrongly too deep.

# This comment belongs with the Background below it.
      Background:
* def payload = 1
                * def base = 'x'

@tagged
   Scenario: a docstring keeps its own shape
Given path base
        * eval
      """
      var doubled = payload * 2;
        if (doubled > 2) {
          doubled = 0;
        }
      """
            Then match payload == 1

  Scenario Outline: tables and examples
          Given path '<id>'
    Then match payload == 1
Examples:
| id |
        | 1  |
