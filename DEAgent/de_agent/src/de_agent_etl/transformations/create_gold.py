import dlt
import pyspark.sql.functions as F
from pyspark.sql.functions import col, current_timestamp, datediff, round, lower, trim

# Bronze Layer: Ingest raw data from source table
@dlt.table(
    name="bookings_bronze",
    comment="Raw bookings data from Wanderbricks source - Bronze layer"
)
def bookings_bronze():
    return (
        spark.readStream
        .table("samples_wanderbricks.wanderbricks.bookings")
        .withColumn("ingestion_timestamp", current_timestamp())
    )


# Silver Layer: Clean and validate data with quality constraints
@dlt.table(
    name="bookings_silver",
    comment="Cleaned and validated bookings data - Silver layer"
)
@dlt.expect_or_drop("valid_booking_id", "booking_id IS NOT NULL")
@dlt.expect_or_drop("valid_dates", "check_out > check_in")
@dlt.expect_or_drop("valid_amount", "total_amount > 0")
@dlt.expect_or_drop("valid_guests", "guests_count > 0")
def bookings_silver():
    return (
        dlt.read_stream("bookings_bronze")
        .withColumn("status", lower(trim(col("status"))))
        .withColumn("nights_count", datediff(col("check_out"), col("check_in")))
        .withColumn("price_per_night", 
                   round(col("total_amount") / datediff(col("check_out"), col("check_in")), 2))
    )