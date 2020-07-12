package StackImplementationUsingLinkedList;

import java.util.EmptyStackException;

public class Stack

{
    
    private Node top;
    private int size;
    
    public Stack() {
    
    }

    private class Node{
        private int data;
        private Node next;
        public Node(int data)
        {
            this.data = data;
            this.next = null;

        }
    }
    //thos method is to add the new element in the top
    public void push(int element)
    {
        Node tempNode = new Node(element);
        tempNode.next = top;
        top = tempNode;
        size++;

    }
    //this method is to return and remot the top element fromt he statck
    public int pop()
    {
        if(isEmpty())
            throw new EmptyStackException();
        int result = top.data;
        top = top.next;    
        size--;
        return result;
    }
    //this method is to return the top element form the stack
    public int peek()
    {

        if(isEmpty())
            throw new EmptyStackException();
        return top.data;
    }

    //this method is to display the data.
    public void displyData()
    {
        Node current = top;
        while(current !=null)
        {
                System.out.print(current.data+"  ");
                current = current.next;
        }
    }
        public boolean isEmpty()
        {
            return size==0;

        }
        public int size()
        {
            return size;
        }



    
}