PRAGMA foreign_keys = ON;

BEGIN;
INSERT INTO categories(category_id, name, shelf_code) VALUES
    (1, 'Computing', 'A-01'),
    (2, 'Science', 'A-02'),
    (3, 'History', 'B-01'),
    (4, 'Biography', 'B-02'),
    (5, 'Fiction', 'C-01'),
    (6, 'Poetry', 'C-02'),
    (7, 'Design', 'D-01'),
    (8, 'Business', 'D-02'),
    (9, 'Travel', 'E-01'),
    (10, 'Philosophy', 'E-02');

INSERT INTO members(member_id, full_name, email, joined_on, membership_status) VALUES
    (1, 'Ada Park', 'ada@example.test', '2024-01-10', 'active'),
    (2, 'Ben Choi', 'ben@example.test', '2024-03-15', 'active'),
    (3, 'Cora Kim', 'cora@example.test', '2024-06-20', 'active'),
    (4, 'Dae Lee', 'dae@example.test', '2024-09-01', 'suspended'),
    (5, 'Eun Han', 'eun@example.test', '2025-01-12', 'active'),
    (6, 'Finn Seo', 'finn@example.test', '2025-02-18', 'active'),
    (7, 'Gina Lim', 'gina@example.test', '2025-04-05', 'active'),
    (8, 'Hugo Yoon', 'hugo@example.test', '2025-07-19', 'active'),
    (9, 'Iris Jung', 'iris@example.test', '2025-10-23', 'suspended'),
    (10, 'Joon Moon', 'joon@example.test', '2026-01-02', 'active');

INSERT INTO books(book_id, category_id, isbn, title, author, published_year, copy_count) VALUES
    (1, 1, '9780000000001', 'Practical Algorithms', 'Mina Cho', 2022, 4),
    (2, 1, '9780000000002', 'Database Foundations', 'Owen Reed', 2021, 5),
    (3, 2, '9780000000003', 'Everyday Astronomy', 'Lena Wu', 2020, 3),
    (4, 3, '9780000000004', 'Cities Through Time', 'Ravi Shah', 2018, 2),
    (5, 4, '9780000000005', 'The Quiet Pioneer', 'Sara Bell', 2019, 2),
    (6, 5, '9780000000006', 'Winter Lanterns', 'Noah Vale', 2023, 6),
    (7, 6, '9780000000007', 'Small Weather', 'Ivy Chen', 2017, 3),
    (8, 7, '9780000000008', 'Useful Interfaces', 'Maya Singh', 2024, 4),
    (9, 8, '9780000000009', 'Patient Strategy', 'Theo Grant', 2022, 5),
    (10, 9, '9780000000010', 'Walking the Coast', 'Nora Pike', 2020, 2),
    (11, 10, '9780000000011', 'Questions of Choice', 'Eli Stone', 2016, 3),
    (12, 1, '9780000000012', 'Reliable Systems', 'June Park', 2025, 7);

INSERT INTO rentals(rental_id, member_id, book_id, borrowed_on, due_on, returned_on, status) VALUES
    (1, 1, 1, '2025-11-01', '2025-11-15', '2025-11-12', 'returned'),
    (2, 1, 2, '2026-01-05', '2026-01-19', NULL, 'overdue'),
    (3, 2, 6, '2025-12-10', '2025-12-24', '2025-12-20', 'returned'),
    (4, 2, 8, '2026-02-01', '2026-02-15', NULL, 'borrowed'),
    (5, 3, 3, '2026-01-20', '2026-02-03', NULL, 'overdue'),
    (6, 3, 12, '2025-10-01', '2025-10-15', '2025-10-14', 'returned'),
    (7, 4, 4, '2025-09-03', '2025-09-17', '2025-09-25', 'returned'),
    (8, 5, 9, '2026-02-03', '2026-02-17', NULL, 'borrowed'),
    (9, 5, 6, '2025-08-01', '2025-08-15', '2025-08-11', 'returned'),
    (10, 6, 10, '2026-01-01', '2026-01-15', NULL, 'overdue'),
    (11, 6, 11, '2025-07-10', '2025-07-24', '2025-07-22', 'returned'),
    (12, 7, 1, '2026-02-05', '2026-02-19', NULL, 'borrowed'),
    (13, 8, 7, '2025-06-01', '2025-06-15', '2025-06-13', 'returned'),
    (14, 8, 12, '2026-01-28', '2026-02-11', NULL, 'borrowed'),
    (15, 9, 5, '2025-05-02', '2025-05-16', '2025-05-14', 'returned');
COMMIT;
