from book_catalog.schemas.books import BookInput, InvalidBookInput


def test_book_input_normalizes_valid_fields() -> None:
    result = BookInput.parse(title="  The Dispossessed  ", author=" Ursula Le Guin ", year="1974")

    assert result == BookInput(title="The Dispossessed", author="Ursula Le Guin", year=1974)


def test_book_input_rejects_blank_and_out_of_range_fields() -> None:
    result = BookInput.parse(title=" ", author="", year="1200")

    assert isinstance(result, InvalidBookInput)
    assert result.fields == frozenset({"title", "author", "year"})
