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
	public void addLat(int item)
	{
		Node node = new Node(item);
		if(isEmpty())
			first = last =node;
		else
		{
			last = node;
			last.next = node;
		}
				
	}
	public void addFirst(int item)	
	{
		Node node = new Node(item);
		if(isEmpty())
			first = last = node;
		else
		{
			node.next = first;
			first = node;
		}
		
	}
	
	public int indexOf(int item)
	{
		int index =0;
		Node current = first;
		while(current!=null)
		{	
			if(current.data == item)
					return index;
			current = current.next;
			index++;
		}
		return -1;
	}
	private boolean isEmpty()
	{
		return first == null;
		
	}
}
