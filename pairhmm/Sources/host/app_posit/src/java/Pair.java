public class Pair {
  int       size;
  char[]    read;
  char[]    hapl;
  float[][] probs;
  
  public String getRead() {
    String ret = new String(read);
    return ret;
  }

  public String getHapl() {
    String ret = new String(hapl);
    return ret;
  }
  
  public void fillProbs() {
	  probs = new float[size][8];
	  
	  for (int j = 0; j < size; j++)
	  {
	  	probs[j][0] = (float) (1.00001 * j);
	  	probs[j][1] = (float) (1.00002 * j);
	  	probs[j][2] = (float) (1.00003 * j);
	  	probs[j][3] = (float) (1.00004 * j);
	  	probs[j][4] = (float) (1.00005 * j);
	  	probs[j][5] = (float) (1.00006 * j);
	  	probs[j][6] = (float) (1.00007 * j);
	  	probs[j][7] = (float) (1.00008 * j);
	  }
  }

  public void setSize(int i) {
	size = i;
  }
};
