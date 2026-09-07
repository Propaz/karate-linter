Feature: docstring bodies that hang left of their delimiter

    Gherkin dedents a body by the column of its opening delimiter and cannot
    remove whitespace that is not there. The first block below sits left of
    its own delimiter, so Karate receives every line of it at column 0 and
    the nesting shown here is not in the string at all. The second block is
    anchored on its delimiter already and must not move.

    Background:
        * def total = 0

    Scenario: body hanging left of the delimiter
        * eval
        """
    for (var i = 0; i < 3; i++) {
      if (i > 1) {
        total = total + i;
      }
    }
        """
        Then match total == 2

    Scenario: body anchored on the delimiter
        * eval
        """
        for (var i = 0; i < 2; i++) {
          total = total + 1;
        }
        """
        Then match total == 2
