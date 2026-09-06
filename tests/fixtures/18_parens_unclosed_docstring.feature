Feature: unclosed docstring with parens inside

    Background:
        * def base = 1

    Scenario: docstring never closed
        * def fn =
        """
        function(x) {
          return foo(
        * def looksLikeAStep = read(

    Scenario: next
        * def after = karate.get(
