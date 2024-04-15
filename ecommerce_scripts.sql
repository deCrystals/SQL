-- Creating Database and Tables
CREATE DATABASE ecommerce;

USE ecommerce;

CREATE TABLE customers
(
cust_id INT AUTO_INCREMENT PRIMARY KEY NOT NULL,
first_name  VARCHAR(20),
last_name  VARCHAR(20),
city  VARCHAR(20),
state VARCHAR(20),
postcode  INT
);
-- INSERT INTO  TABLE customers (cust_id, first_name, last_name, city, state, postcode,)
-- VALUES('');

CREATE TABLE products
(
prod_id INT AUTO_INCREMENT PRIMARY KEY NOT NULL,
name VARCHAR(70),
stock_quantity INT,
price FLOAT,
cate_id INT,
category VARCHAR(50),
description VARCHAR(70)
);

CREATE TABLE category
(
cate_id INT AUTO_INCREMENT PRIMARY KEY,
name VARCHAR(50),
descript VARCHAR(50)
);

CREATE TABLE sub_category
(
subcat_id INT AUTO_INCREMENT PRIMARY KEY,
subcat_name VARCHAR(50),
description VARCHAR(50),
category_id INT
);

CREATE TABLE cart
(
cart_id INT AUTO_INCREMENT PRIMARY KEY,
cust_id INT,
prod_id INT,
quantity INT,
date DATETIME
);

CREATE TABLE orders
(
ord_id INT AUTO_INCREMENT PRIMARY KEY,
cart_id INT,
cust_id INT,
ord_date varchar(50),
pay_stat varchar(50)
);


CREATE TABLE order_detail
(
id INT AUTO_INCREMENT PRIMARY KEY,
ord_id INT,
prod_id INT,
quantity INT,
unit_price INT,
pay_id INT
);


CREATE TABLE payments
(
pay_id INT AUTO_INCREMENT PRIMARY KEY,
date VARCHAR(50),
cust_id INT,
ord_id INT,
pay_mtd VARCHAR(50),
status VARCHAR(50)
);

CREATE TABLE shipping
(
id  INT  AUTO_INCREMENT PRIMARY KEY ,
ord_id  INT,
date DATETIME,
status VARCHAR(50)
); 

-- creating foreign keys

ALTER TABLE products
ADD FOREIGN KEY (cate_id) REFERENCES category(cate_id);


ALTER TABLE orders
ADD FOREIGN KEY (cust_id) REFERENCES customers(cust_id),
ADD FOREIGN KEY (cart_id) REFERENCES cart(cart_id);

ALTER TABLE payments
ADD FOREIGN KEY (cust_id) REFERENCES customers(cust_id),
ADD FOREIGN KEY (ord_id) REFERENCES order_detail(id);

ALTER TABLE order_detail
ADD FOREIGN KEY (ord_id) REFERENCES orders(ord_id),
ADD FOREIGN KEY (prod_id) REFERENCES products(prod_id),
ADD FOREIGN KEY (pay_id) REFERENCES payments(pay_id);

ALTER TABLE cart
ADD FOREIGN KEY (cust_id) REFERENCES customers(cust_id),
ADD FOREIGN KEY (prod_id) REFERENCES products(prod_id);

ALTER TABLE shipping
ADD FOREIGN KEY (ord_id) REFERENCES order_detail(id);

ALTER TABLE sub_category
ADD FOREIGN KEY (category_id) REFERENCES category(cate_id);

-- INSERT INTO  TABLE customers (cust_id, first_name, last_name, city, state, postcode,)
-- VALUES('');

-- stored function to calculate total
DELIMITER //
CREATE FUNCTION total_calculate(ord INT)
RETURNS DECIMAL(10, 2) DETERMINISTIC
BEGIN
DECLARE total DECIMAL(10, 2);
    SELECT  SUM(unit_price * quantity)
    INTO total
    FROM order_detail
	WHERE ord =ord_id;
	RETURN total;
 
END//
DELIMITER ;


-- using the stored function
SELECT ord_id, unit_price, quantity, total_calculate(ord_id) as Total
from
order_detail;

  
-- Stored Procedure
DELIMITER //
CREATE PROCEDURE ordervalue(IN order_id INT, OUT order_idout INT, OUT total DECIMAL(10,2), OUT status VARCHAR(20))
BEGIN
	DECLARE order_total DECIMAL(10, 2);
	DECLARE order_status VARCHAR(20);
    
-- calling the function inside the procedure
	SET order_total = total_calculate(order_id);
    
	IF order_total >= 500 THEN
		SET order_status = 'High Value Order';
	ELSEIF order_total >= 100 THEN
		SET order_status = 'Medium Value Order';
	ELSE
		SET order_status ='Low Value Order';
	END IF ;
	-- setting the output
    SET order_idout = order_id;
    SET total = order_total;
    SET status = order_status;
END //

DELIMITER ;

-- calling the stored procedure 
-- CALL ordervalue(7078, @order_id, @total, @status);
-- SELECT @order_id AS order_id, @total AS total_value, @status AS status;

-- sales view by joining order and order details table
CREATE VIEW sales
AS
SELECT o.ord_id, o.date, ord.prod_id, ord.unit_price, ord.quantity, total_calculate(o.ord_id) as Total_Amount
FROM
order_detail ord
JOIN orders o ON ord.ord_id= o.ord_id;

-- loading sales view 
-- SELECT * FROM sales;

-- SUBQUERY: getting product with averade sales more than 200 using the Sales view
SELECT name, price
FROM products
WHERE prod_id IN (
    SELECT prod_id
    FROM sales
    GROUP BY prod_id
    HAVING AVG(total_amount) > 200.00
    );
    
-- creating reports view by joining 7 tables
CREATE VIEW reports
AS
SELECT c.cust_id, c.first_name, c.last_name, c.city, c.state, 
o.date, p.name 'Product Name', cy.name 'Category', o.ord_id 'Order ID',
ord.quantity 'Quantity', p.price 'Price', py.pay_mtd 'Payment Method', total_calculate(o.ord_id) as Total_Amount, py.status, 
sh.status 'Shipping Status'
FROM
customers c
JOIN orders o ON o.cust_id = c.cust_id
JOIN order_detail ord  ON ord.ord_id = o.ord_id
JOIN products p ON p.prod_id = ord.prod_id
JOIN payments py ON py.pay_id = ord.pay_id
JOIN shipping sh ON sh.ord_id = o.ord_id
JOIN category cy ON cy.cate_id = p.cate_id;

-- trigger to update order status and products stock quantity when payment is made
DELIMITER //
CREATE TRIGGER payment_made
AFTER INSERT ON payments
FOR EACH ROW
BEGIN
	-- update the status 
	IF NEW.status = 'paid' THEN
		UPDATE orders
		SET status ='complete'
        WHERE ord_id = NEW.ord_id;
	ELSEIF  NEW.status = 'pending' THEN
		UPDATE orders
		SET status = 'pending'
        WHERE ord_id = NEW.ord_id;
	ELSE 
		UPDATE orders
		SET status = 'cancelled' 
		WHERE ord_id = NEW.ord_id;
	END IF;
END;

-- update products when payment is made
CREATE TRIGGER order_placed 
AFTER INSERT ON orders
FOR EACH ROW
BEGIN
	IF orders.status = 'complete' THEN
		UPDATE products
		SET stock_quantity = stock_quantity - (SELECT quantity FROM order_detail WHERE (order_id = NEW.ord_id) AND (prod_id = NEW.prod_id))
		WHERE prod_id IN(SELECT prod_id FROM order_detail WHERE ord_id = NEW.ord_id);
	END IF;
END;
//
DELIMITER ;

    
-- Event daily report update
-- Event : creating saless report table to store the daily sales

CREATE TABLE sales_reports (
    rpt_id INT AUTO_INCREMENT PRIMARY KEY,
    rprt_date DATE,
    total_sales_amount DECIMAL(10, 2),
    created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DELIMITER //
CREATE EVENT daily_sales_report
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY
DO
BEGIN
    -- Generate daily sales report and store it in a table
    INSERT INTO sales_reports (rpt_date, total_sales_amount)
    SELECT CURRENT_DATE, SUM(total_amount)
    FROM sales
    WHERE DATE(date) = CURRENT_DATE;
END ; //
DELIMITER ;

