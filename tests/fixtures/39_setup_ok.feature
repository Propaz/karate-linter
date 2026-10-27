Feature: setup scenarios feeding dynamic outlines

    Nothing in this file may be reported. A one-cell Examples table is an
    expression, not a header, and every karate.setup() call here finds its
    @setup Scenario and every field it reads.

    Background:
        * def base = 1

    @setup
    Scenario:
        * def cats = [{ name: 'a' }, { name: 'b' }]
        * def generator = function(i){ if (i == 2) return null; return { name: 'g' + i } }

    @smoke @setup=extra,more
    Scenario: named setup
        * json dogs = [{ name: 'd' }]

    # a call without assignment shares its scope, so any field may come back
    @setup=implicit
    Scenario: setup with a shared-scope call
        * call read('make-birds.feature')

    Scenario Outline: first cat <name>
        * match name == '<name>'
        * match base == 1

        Examples:
            | karate.setupOnce().cats |

    Scenario Outline: generated ${name}
        * print name

        Examples:
            | karate.setup().generator |

    Scenario Outline: dog ${name}
        * print name

        Examples:
            | karate.setup('more').dogs |

    Scenario Outline: bird ${name}
        * print name

        Examples:
            | karate.setupOnce("implicit").birds |

    Scenario Outline: from a file ${name}
        * print name

        Examples:
            | read('cats.json') |

    Scenario: setup reached from a js payload
        * def fn =
        """
        function() { return karate.setup('extra').dogs }
        """
        * def got = fn()
        * match got == '#[1]'
