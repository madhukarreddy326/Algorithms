public class fizbuzz_example{
    public static void main(String[] args) {
        System.out.println("this is to demonstrate the fizzbuzz example ");

        int arr[]={1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};

        for (int i : arr)           
        {
            if(i%15==0)
               System.out.println(i+": is fizz-buzz");
            else if(i%3==0)
                System.out.println(i+": if fizz");
            else if(i%5==0)
                System.out.println(i+": is buzz");
            
        }
        

    }
}