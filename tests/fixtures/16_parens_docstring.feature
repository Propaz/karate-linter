Feature: docstring immunity

    Background:
        * def base = 1

    Scenario: js in a docstring
        * def fn =
        """
        function(x) {
          return foo(
            x
          );
        }
        """
        * def out = fn(base)
