import numpy
import struct

def f2h(f):
    return format(struct.unpack('<I', struct.pack('<f', f))[0],'x')

def printvalues(vals):
  for value in vals:
    print f2h(value)

al = 1.0
be = 1.0
ga = 1.0
de = 1.0
ep = 1.0
ze = 1.0
et = 1.0
la = 1.0
th = 1.0
up = 1.0

for h in range(0, 4):

  M = numpy.zeros(shape=(5,5))
  I = numpy.zeros(shape=(5,5))
  D = numpy.zeros(shape=(5,5))

  M[0][0] = 1.0

  for i in range(1, 5):

    #print [f2h(al), f2h(be), f2h(ga), f2h(de), f2h(ep), f2h(ze), f2h(et), f2h(la), f2h(th), f2h(up)]
    #printvalues([al, be, ga, de, ep, ze, et, la, th, up])
    #print '--'

    for j in range(1, 5):
      M[i][j] = la * (al * M[i-1][j-1]  + be * I[i-1][j-1] + ga * D[i-1][j-1])
      I[i][j] = th * (de * M[i-1][j]    + ep * I[i-1][j])
      D[i][j] = up * (ze * M[i][j-1]    + et * D[i][j-1])

    al = al * 1.0
    be = be * 1.0
    ga = ga * 1.0
    de = de * 1.0
    ep = ep * 1.0
    ze = ze * 1.0
    et = et * 1.0
    la = la * 1.0
    th = th * 1.0
    up = up * 1.0


  print [i, j]
  print "M:"
  print M
  print "I:"
  print I
  print "D:"
  print D
