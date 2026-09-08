Feature: a tag that introduces something other than Examples

    The first outline never gets a table, and the tag below it belongs to the
    scenario that follows, not to an Examples block — so the outline must
    still be reported. Exactly one finding is expected here.

    Background:
        * def region = 'north'

    Scenario Outline: no table anywhere
        Given path 'orders/<id>'
        Then match region == 'north'

    @smoke
    Scenario: the tagged scenario the tag really introduces
        Then match region == 'north'
