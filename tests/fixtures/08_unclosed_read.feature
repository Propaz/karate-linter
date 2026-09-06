Feature: unclosed read

    Background:
        * def base = 1

    Scenario: read
        * def data = read('file.json'
        Then match data == base
