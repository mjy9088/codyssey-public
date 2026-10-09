PRAGMA foreign_keys = ON;

BEGIN;
DROP TABLE IF EXISTS rentals;
DROP TABLE IF EXISTS books;
DROP TABLE IF EXISTS members;
DROP TABLE IF EXISTS categories;

CREATE TABLE categories (
    category_id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    shelf_code TEXT NOT NULL UNIQUE
);

CREATE TABLE members (
    member_id INTEGER PRIMARY KEY,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    joined_on TEXT NOT NULL CHECK (joined_on = date(joined_on)),
    membership_status TEXT NOT NULL CHECK (membership_status IN ('active', 'suspended'))
);

CREATE TABLE books (
    book_id INTEGER PRIMARY KEY,
    category_id INTEGER NOT NULL,
    isbn TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    author TEXT NOT NULL,
    published_year INTEGER NOT NULL CHECK (published_year BETWEEN 1450 AND 2100),
    copy_count INTEGER NOT NULL CHECK (copy_count >= 0),
    FOREIGN KEY (category_id) REFERENCES categories(category_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE rentals (
    rental_id INTEGER PRIMARY KEY,
    member_id INTEGER NOT NULL,
    book_id INTEGER NOT NULL,
    borrowed_on TEXT NOT NULL CHECK (borrowed_on = date(borrowed_on)),
    due_on TEXT NOT NULL CHECK (due_on = date(due_on) AND due_on >= borrowed_on),
    returned_on TEXT CHECK (returned_on IS NULL OR returned_on = date(returned_on)),
    status TEXT NOT NULL CHECK (status IN ('borrowed', 'returned', 'overdue')),
    CHECK (
        (status = 'returned' AND returned_on IS NOT NULL)
        OR (status IN ('borrowed', 'overdue') AND returned_on IS NULL)
    ),
    FOREIGN KEY (member_id) REFERENCES members(member_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (book_id) REFERENCES books(book_id) ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE INDEX idx_rentals_member_id ON rentals(member_id);
CREATE INDEX idx_rentals_book_status ON rentals(book_id, status);
COMMIT;
