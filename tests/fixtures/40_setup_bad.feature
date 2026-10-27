Feature: setup scenarios that cannot work

    Background:
        * def base = 1

    @setup=cats
    Scenario: cats
        * def cats = [{ name: 'a' }]

    @setup=orphan
    Scenario: never called
        * print 'nobody asks for this'

    @setup=outline
    Scenario Outline: setup on an outline <x>
        * print '<x>'

        Examples:
            | x |
            | 1 |

    Scenario Outline: wrong name ${name}
        * print name

        Examples:
            | karate.setup('dogs').list |

    Scenario Outline: unknown field ${name}
        * print name + base

        Examples:
            | karate.setupOnce('cats').kittens |

    Scenario Outline: an outline is never a setup ${name}
        * print name

        Examples:
            | karate.setup('outline').rows |
