local serializer = import("methods/serializer")

return {
    dataToString = serializer.dataToString,
    quoteString = serializer.quoteString,
    serializeArgs = serializer.serializeArgs,
    toString = serializer.toString,
    toUnicode = serializer.toUnicode,
}
