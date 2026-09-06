Feature: long multibyte diagnostic

    Background:
        * def base = 1

    Scenario Outline: placeholder with a long cyrillic name
        Given path '<переменнаяСОченьДлиннымИменемДляПроверкиОбрезкиПоШиринеЯчеекИЛимитаДлиныСтрокиИзмеряемогоВКолонкахАНеВБайтах>'

        Examples:
            | id |
            | 1  |
