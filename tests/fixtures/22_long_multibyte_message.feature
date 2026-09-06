Feature: long multibyte diagnostic

    Background:
        * def base = 1

    Scenario Outline: placeholder with a long cyrillic name
        Given path '<переменнаяСОченьДлиннымИменемДляПроверкиОбрезкиПоШиринеЯчеек>'

        Examples:
            | id |
            | 1  |
