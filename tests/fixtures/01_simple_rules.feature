Feature: simple rules

    Background:
        * def base = 1

    Scenario: whitespace and keyword rules
        Given url 'http://example.com'
	    And path 'items'
        Then status 200   
        But match base == 1
        When'no space here'
        * def payload = callread('big.json')
        * def unusedOne = 42
        And match response == { a: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' }
