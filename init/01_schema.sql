CREATE TABLE customers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  customer_id INT NOT NULL REFERENCES customers(id),
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','paid','shipped')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE order_items (
  id SERIAL PRIMARY KEY,
  order_id INT NOT NULL REFERENCES orders(id),
  product TEXT NOT NULL,
  qty INT NOT NULL CHECK (qty > 0),
  price NUMERIC(10,2) NOT NULL
);
CREATE INDEX ON orders(customer_id);
CREATE INDEX ON order_items(order_id);

INSERT INTO customers (name, email)
SELECT 'Customer '||g, 'user'||g||'@example.com' FROM generate_series(1,100) g;

INSERT INTO orders (customer_id, status)
SELECT 1+(g%100), (ARRAY['new','paid','shipped'])[1+(g%3)] FROM generate_series(1,300) g;

INSERT INTO order_items (order_id, product, qty, price)
SELECT 1+(g%300), 'Product '||(1+g%20), 1+(g%5), round((5+random()*95)::numeric,2)
FROM generate_series(1,800) g;
