Feature: parens that are fine (really
    A free-text description with an unmatched ( paren

    Background:
        * def base = 1

    Scenario: smoke test (part 1
        * call read('x.feature')
        * def s = read('has_).json')
        * def t = read('a.json') 
        * def nested = read(foo(bar))
        * def q = karate.call('a.feature', { id: 1 })
        * def paren = 'a ( b'
        * def dq = "unbalanced ( inside double quotes"
        * def tick = `template ( literal`
        * def esc = 'it\'s ( escaped'
        * def url = karate.get('http://example.com/a')
        * def cmt = base // trailing comment (
        # commented out: read('a.json'
        * def grouping = (base + 1

        Examples:
            | a | read( |
