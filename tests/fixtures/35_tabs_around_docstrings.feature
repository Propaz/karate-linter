Feature: tabs around a docstring

    Background:
        * def a = 1

    Scenario: a structural tab is fixed, a payload tab is not
	Given path 'orders'
        And request
        """
        outer
        	deeper than the delimiter
        """
        Then match a == 1

    Scenario: a tab on the delimiter line itself
        And request
	"""
        outer
        """
        Then match a == 1
