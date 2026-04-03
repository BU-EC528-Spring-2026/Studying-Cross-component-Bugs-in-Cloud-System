  test("repro SPARK-50137 on 3.5.3: thrift exception wrongly falls back") {
    val conf = new Configuration()
    conf.set("hive.metastore.uris", "thrift://192.0.2.1:9083")
    conf.set("hive.metastore.client.connection.timeout", "1s")

    val catalog = new HiveExternalCatalog(new SparkConf(), conf) {
      override def requireDbExists(db: String): Unit = ()
      override def tableExists(db: String, table: String): Boolean = false
    }

    val appender = new LogAppender()
    withLogAppender(appender, level = Some(Level.WARN)) {
      val tbl = CatalogTable(
        identifier = TableIdentifier("repro_50137", Some("default")),
        tableType = CatalogTableType.EXTERNAL,
        storage = storageFormat.copy(locationUri = Some(newUriForDatabase())),
        schema = new StructType().add("c1", "string"),
        provider = Some("parquet"))

      intercept[Throwable] {
        catalog.createTable(tbl, ignoreIfExists = false)
      }
    }

    assert(appender.loggingEvents.exists { e =>
      val m = e.getMessage.getFormattedMessage
      m.contains("Could not persist `default`.`repro_50137`") &&
      m.contains("Hive compatible way")
    })
  }
