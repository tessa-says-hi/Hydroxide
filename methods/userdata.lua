local serializer = import("methods/serializer")

return {
    getInstancePath = serializer.getInstancePath,
    isUserdata = serializer.isUserdata,
    userdataValue = serializer.userdataValue,
}
