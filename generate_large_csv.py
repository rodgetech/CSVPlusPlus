#!/usr/bin/env python3
import csv
import random
from datetime import datetime, timedelta
import sys

def generate_large_csv(filename, num_rows):
    departments = ["Engineering", "Marketing", "Sales", "HR", "Finance", "IT", "Operations", "Legal", "R&D", "Customer Service"]
    locations = ["New York", "San Francisco", "Chicago", "Los Angeles", "Boston", "Seattle", "Austin", "Miami", "Denver", "Portland"]
    first_names = ["John", "Sarah", "Michael", "Emily", "Robert", "Lisa", "David", "Jennifer", "William", "Amanda",
                   "Christopher", "Michelle", "Daniel", "Patricia", "James", "Linda", "Mark", "Barbara", "Steven", "Susan",
                   "Kevin", "Jessica", "Brian", "Ashley", "Jason", "Stephanie", "Ryan", "Nicole", "Andrew", "Rachel"]
    last_names = ["Smith", "Johnson", "Chen", "Davis", "Wilson", "Anderson", "Martinez", "Taylor", "Brown", "Jones",
                  "Lee", "Garcia", "Rodriguez", "Miller", "Hernandez", "Lopez", "Gonzalez", "Thomas", "Jackson", "White",
                  "Harris", "Martin", "Thompson", "Moore", "Young", "Allen", "King", "Wright", "Scott", "Green"]
    
    # Marketing campaigns for generating impressions/revenue data
    campaigns = ["Google Ads", "Facebook Ads", "Instagram Ads", "LinkedIn Ads", "Twitter Ads", "TikTok Ads", 
                "Email Campaign", "Display Ads", "YouTube Ads", "Pinterest Ads"]
    
    print(f"Generating {num_rows:,} rows in {filename}...")
    
    with open(filename, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)
        
        # Write header with new metrics columns
        writer.writerow([
            "ID", "Name", "Department", "Salary", "Age", "Start Date", 
            "Performance Score", "Location", "Email", "Active",
            "Campaign", "Impressions", "Revenue", "CTR", "Conversion Rate"
        ])
        
        # Generate rows
        start_date = datetime(2015, 1, 1)
        
        for i in range(1, num_rows + 1):
            first = random.choice(first_names)
            last = random.choice(last_names)
            name = f"{first} {last}"
            department = random.choice(departments)
            salary = random.randint(45000, 150000)
            age = random.randint(22, 65)
            
            # Random date between 2015 and 2023
            random_days = random.randint(0, 365 * 8)
            hire_date = start_date + timedelta(days=random_days)
            hire_date_str = hire_date.strftime("%Y-%m-%d")
            
            performance = round(random.uniform(3.0, 5.0), 1)
            location = random.choice(locations)
            email = f"{first.lower()}.{last.lower()}{random.randint(1,999)}@company.com"
            active = random.choice(["true", "false"])
            
            # New metrics columns
            campaign = random.choice(campaigns)
            impressions = random.randint(1000, 1000000)  # 1K to 1M impressions
            revenue = round(random.uniform(10.50, 25000.75), 2)  # $10.50 to $25K revenue
            ctr = round(random.uniform(0.1, 8.5), 2)  # 0.1% to 8.5% CTR
            conversion_rate = round(random.uniform(0.5, 15.0), 2)  # 0.5% to 15% conversion rate
            
            writer.writerow([
                i, name, department, salary, age, hire_date_str, 
                performance, location, email, active,
                campaign, impressions, revenue, ctr, conversion_rate
            ])
            
            # Progress indicator
            if i % 25000 == 0:
                print(f"Generated {i:,} rows... ({(i/num_rows)*100:.1f}%)")
    
    print(f"✅ Successfully generated {num_rows:,} rows in {filename}")
    print(f"📁 File size: ~{(num_rows * 200) // 1024 // 1024} MB")

def main():
    if len(sys.argv) > 1:
        try:
            num_rows = int(sys.argv[1])
            if num_rows < 1000:
                print("⚠️  Minimum 1,000 rows recommended")
                return
            
            if num_rows >= 1000000:
                filename = f"mega_sample_{num_rows//1000}k.csv"
                print(f"🚀 Generating MEGA dataset with {num_rows:,} rows...")
                print("⏱️  This will take a few minutes...")
            else:
                filename = f"sample_{num_rows//1000}k.csv"
            
            generate_large_csv(filename, num_rows)
            
        except ValueError:
            print("❌ Please provide a valid number of rows")
            print("Usage: python3 generate_large_csv.py <number_of_rows>")
    else:
        # Default generations
        print("🏃 Quick test files:")
        generate_large_csv("sample_10k.csv", 10000)
        print()
        
        print("🔥 Performance test files:")
        generate_large_csv("sample_100k.csv", 100000)
        print()
        
        print("🚀 MEGA performance test (1M+ rows):")
        generate_large_csv("mega_sample_1000k.csv", 1000000)
        print()
        
        print("💡 To generate custom size:")
        print("   python3 generate_large_csv.py 2000000  # 2 million rows")
        print("   python3 generate_large_csv.py 5000000  # 5 million rows")

if __name__ == "__main__":
    main()