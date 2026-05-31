f = open('lib/screens/home_screen.dart', 'rb')
data = f.read()
f.close()

# Now the file has single quotes but still has \\ before $
# Replace \\$ with $ only in the specific places we want
data = data.replace(
    b"'Route Summary (\\${_currentRoute.length - 1} stops)'",
    b"'Route Summary (${_currentRoute.length - 1} stops)'"
)
data = data.replace(
    b"'\\${_currentRoute.first.name}  \xe2\x86\x92  \\${_currentRoute.last.name}'",
    b"'${_currentRoute.first.name}  \xe2\x86\x92  ${_currentRoute.last.name}'"
)

f = open('lib/screens/home_screen.dart', 'wb')
f.write(data)
f.close()

# Verify
f = open('lib/screens/home_screen.dart', 'rb')
d = f.read()
f.close()
i = d.find(b'Route Summary')
print("Route Summary line:", repr(d[i:i+60]))
i2 = d.find(b'currentRoute.first')
print("First name line:", repr(d[i2-3:i2+60]))
