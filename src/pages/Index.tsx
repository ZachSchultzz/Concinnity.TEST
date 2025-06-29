import { Button } from "@/components/ui/button";

const Index = () => {
  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-emerald-50 flex items-center justify-center">
      <div className="text-center">
        <h1 className="text-4xl font-bold text-gray-900 mb-4">
          Welcome to Concinnity
        </h1>
        <p className="text-lg text-gray-600 mb-8">
          Work Together, Brilliantly!
        </p>
        <Button className="bg-gradient-blue-emerald hover:bg-gradient-emerald-blue text-white">
          Get Started
        </Button>
      </div>
    </div>
  );
};

export default Index;