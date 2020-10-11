package LinkedList;

public class LinkedList {
	private Node first;
	private Node last;
	private class Node{
		private int data;
		private Node next;
	
	Node(int item)
	{
		this.data = item;
	}
	
	}
	public void addFirst(int item)
	{
		Node node = new Node(item);
		if(first ==null)
			first = last =node;
		else
		{
			last = node;
			last.next = node;
		}
		
		
	}
}
