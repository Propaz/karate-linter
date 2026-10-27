Feature: type-hinted Examples columns

    Background:
        * def base = 1

    Scenario Outline: hinted columns are named without the bang <name>
        * match <count> == count + base - 1
        * def body =
        """
        { "alive": <alive> }
        """
        * match body.alive == alive

        Examples:
            | name | count! | alive! |
            | Bob  | 5      | false  |

    Scenario Outline: the bang is not part of the name
        * print <flag!>, <id>

        Examples:
            | flag! | id | id! | extra! |
            | true  | 1  | 2   | 3      |
