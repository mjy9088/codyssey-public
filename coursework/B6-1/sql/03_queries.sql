PRAGMA foreign_keys = ON;

-- Q01 Basic: newest books with at least four copies; demonstrates WHERE, ORDER BY, and LIMIT.
SELECT 'Q01 newest well-stocked books' AS result_set;
SELECT title, published_year, copy_count
FROM books
WHERE copy_count >= 4
ORDER BY published_year DESC, title ASC
LIMIT 5;

-- Q02 Basic: members who joined in 2025 or later.
SELECT 'Q02 recent members' AS result_set;
SELECT full_name, joined_on, membership_status
FROM members
WHERE joined_on >= '2025-01-01'
ORDER BY joined_on ASC;

-- Q03 Basic: active members ordered by name with a bounded result.
SELECT 'Q03 active members' AS result_set;
SELECT member_id, full_name, email
FROM members
WHERE membership_status = 'active'
ORDER BY full_name ASC
LIMIT 6;

-- Q04 Basic: open loans due first.
SELECT 'Q04 open loans' AS result_set;
SELECT rental_id, member_id, book_id, due_on, status
FROM rentals
WHERE status IN ('borrowed', 'overdue')
ORDER BY due_on ASC, rental_id ASC
LIMIT 10;

-- Q05 Inner join: readable open-loan list across rentals, members, and books.
SELECT 'Q05 open-loan details' AS result_set;
SELECT r.rental_id, m.full_name, b.title, r.due_on, r.status
FROM rentals AS r
INNER JOIN members AS m ON m.member_id = r.member_id
INNER JOIN books AS b ON b.book_id = r.book_id
WHERE r.status IN ('borrowed', 'overdue')
ORDER BY r.due_on, r.rental_id;

-- Q06 Inner join: books with their normalized category location.
SELECT 'Q06 book categories' AS result_set;
SELECT b.title, c.name AS category, c.shelf_code
FROM books AS b
INNER JOIN categories AS c ON c.category_id = b.category_id
ORDER BY c.name, b.title;

-- Q07 Left join: every member remains visible, including members with zero rentals.
SELECT 'Q07 rental count per member' AS result_set;
SELECT m.full_name, COUNT(r.rental_id) AS rental_count
FROM members AS m
LEFT JOIN rentals AS r ON r.member_id = m.member_id
GROUP BY m.member_id, m.full_name
ORDER BY rental_count DESC, m.full_name;

-- Q08 Inner join: overdue member contact list.
SELECT 'Q08 overdue contacts' AS result_set;
SELECT m.full_name, m.email, b.title, r.due_on
FROM rentals AS r
INNER JOIN members AS m ON m.member_id = r.member_id
INNER JOIN books AS b ON b.book_id = r.book_id
WHERE r.status = 'overdue'
ORDER BY r.due_on, m.full_name;

-- Q09 Aggregate: rental volume by category.
SELECT 'Q09 category rental volume' AS result_set;
SELECT c.name, COUNT(r.rental_id) AS rental_count
FROM categories AS c
LEFT JOIN books AS b ON b.category_id = c.category_id
LEFT JOIN rentals AS r ON r.book_id = b.book_id
GROUP BY c.category_id, c.name
ORDER BY rental_count DESC, c.name;

-- Q10 Aggregate: total inventory by category.
SELECT 'Q10 category inventory' AS result_set;
SELECT c.name, SUM(b.copy_count) AS total_copies
FROM categories AS c
INNER JOIN books AS b ON b.category_id = c.category_id
GROUP BY c.category_id, c.name
ORDER BY total_copies DESC, c.name;

-- Q11 Aggregate: SQLite julianday computes average completed-loan duration.
SELECT 'Q11 average completed duration' AS result_set;
SELECT ROUND(AVG(julianday(returned_on) - julianday(borrowed_on)), 2) AS average_days
FROM rentals
WHERE status = 'returned';

-- Q12 Subquery: books whose inventory is above the overall average.
SELECT 'Q12 above-average inventory' AS result_set;
SELECT title, copy_count
FROM books
WHERE copy_count > (SELECT AVG(copy_count) FROM books)
ORDER BY copy_count DESC, title;

-- Q13 Subquery bonus: members without rentals, expressed with NOT EXISTS.
SELECT 'Q13 members without rentals' AS result_set;
SELECT m.member_id, m.full_name
FROM members AS m
WHERE NOT EXISTS (
    SELECT 1 FROM rentals AS r WHERE r.member_id = m.member_id
)
ORDER BY m.member_id;

-- Q14 Update: close one overdue loan and report its new state.
SELECT 'Q14 update overdue loan' AS result_set;
UPDATE rentals
SET returned_on = '2026-02-12', status = 'returned'
WHERE rental_id = 5;
SELECT rental_id, returned_on, status FROM rentals WHERE rental_id = 5;

-- Q15 Delete: remove a selected historical record and report the remaining count.
SELECT 'Q15 delete historical rental' AS result_set;
DELETE FROM rentals WHERE rental_id = 15;
SELECT COUNT(*) AS remaining_rentals FROM rentals;

-- Q16 Insert: create a new valid loan and show its linked IDs.
SELECT 'Q16 insert new rental' AS result_set;
INSERT INTO rentals(rental_id, member_id, book_id, borrowed_on, due_on, returned_on, status)
VALUES (16, 10, 2, '2026-02-10', '2026-02-24', NULL, 'borrowed');
SELECT rental_id, member_id, book_id, status FROM rentals WHERE rental_id = 16;

-- Q17 Index: SQLite metadata confirms the search index used for member loan lookups.
SELECT 'Q17 member lookup index' AS result_set;
CREATE INDEX IF NOT EXISTS idx_rentals_member_id ON rentals(member_id);
SELECT name, sql
FROM sqlite_master
WHERE type = 'index' AND name = 'idx_rentals_member_id';
