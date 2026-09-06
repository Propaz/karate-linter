Feature: request vars

    Background:
        * def base = 1

    Scenario: request
        Given request notDefined
        * def payload = { a: 1 }
        When request payload
