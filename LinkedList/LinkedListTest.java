package LinkedList;

public class LinkedListTest {
	
	public void main(String args[])
	{
		LinkedList linkedList = new LinkedList();
		linkedList.addFirst(10);
		linkedList.addFirst(20);
		linkedList.addFirst(30);
		System.out.println(linkedList.indexOf(10));
	}

}
