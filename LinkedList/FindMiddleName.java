package LinkedList;

public class FindMiddleName {
public static void main(String args[])
{
	LinkedList1 linkedList = new LinkedList1();
	LinkedList1.Node head =linkedList.head();
	linkedList.add(new LinkedList1.Node("1"));
	linkedList.add(new LinkedList1.Node("2"));
	linkedList.add(new LinkedList1.Node("3"));
	linkedList.add(new LinkedList1.Node("4"));
	LinkedList1.Node current = head;
	int length =0;
	LinkedList1.Node middle = head;
	
	while(current.next() !=null)
	{
		length++;
		if(length%2 ==0)
		{
			middle = middle.next();			
		}
		current = current.next();
	}
	if(length%2==1)
	{
		middle = middle.next();
	}
	System.out.println("length of LInkedList :  "+length);
	System.out.println("middle element of LinkedList : "+middle);
	
}
}
class LinkedList1
{
	private Node head;
	private Node tail;
	
	public LinkedList1()
	{
		this.head = new Node("head");
		tail = head;
	}
	public Node head()
	{
		return head;
		
	}
	public void add(Node node)
{
	tail.next = node;
	tail = node;
}

public static class Node
{
	private Node next;
	private String data;
	
	public Node(String data)
	{
		this.data = data;
	}
	public String data()
	{
		return data;
	}
	public void setData(String data)
	{
		this.data = data;
	}
	public Node next()
	{
		return next;
	}
	public void setNext(Node next)
	{
		this.next = next;
	}
	public String toString()
	{
		return this.data;
	}
	
}
}
