public class StackClient{


public static void main(String args[]){

        Stack stack = new Stack(5);

        System.out.println("is Stack Empty: "+stack.isEmpty());
        System.out.println("Is Stack Full: "+stack.isFull());
        System.out.println("Find the size of the stack: "+stack.size());

        stack.push(10);
        stack.push(20);
        stack.push(30);
        stack.push(40);
        stack.push(50);
    
        System.out.println("is Stack Empty: "+stack.isEmpty());
        System.out.println("Is Stack Full: "+stack.isFull());
        System.out.println("Find the size of the stack: "+stack.size());

        System.out.println("stack is: "+stack);
        System.out.println("Pop element is : "+stack.pop());

        System.out.println("Peek element is:: "+stack.peek());

        System.out.println("Find the size of the stack: "+stack.size());

}
}