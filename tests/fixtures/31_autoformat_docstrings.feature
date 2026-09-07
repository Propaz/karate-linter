Feature: docstrings survive auto-format on save

    A clean file, so auto-format-on-save actually runs: it refuses while the
    buffer has errors. Every block below has body indentation of its own, and
    there is more than one of them - the restore loop that gg=G needed used to
    abort on the first block it spliced, leaving the rest of the file
    reindented and unrestored. This file must come back untouched.

    Background:
        * def payload = 1

    Scenario: js block
        * eval
        """
        for (var i = 0; i < 3; i++) {
        var doubled = i * 2;
        if (doubled > 2) {
        break;
        }
        }
        """
        Then match payload == 1

    Scenario: json block
        * def body =
        """
        {
        "a": 1,
        "nested": {
        "b": [1, 2]
        }
        }
        """
        Then match body.a == 1

    Scenario: one-line block
        * def note =
        """
        single
        """
        Then match note == 'single'
