Feature: no setup scenario at all

    Background:
        * def base = 1
        * def which = 'cats'

    Scenario Outline: cat ${name}
        * print name, base

        Examples:
            | karate.setupOnce().cats |

    # the name is only known at run time, so this one cannot be judged
    Scenario Outline: chosen at run time ${name}
        * print name

        Examples:
            | karate.setup(which).cats |
