Feature: what leaks into docstrings

    Background:
        * def base = 1

    Scenario: well formed docstring with hostile content
        Given request
        """
        {
          "note": "the lines below are JSON/JS, not Karate steps",
        * def phantomVar = 999
	  "tabbed": true,
          "trailing": true   
        But this line starts with But
        *noSpaceAfterStar
        Given request neverDefinedVar
          "long": "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
        * def viaRead = read('unclosed.json'
        }
        """
        Then match base == 1
