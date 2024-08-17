# FETCH CURRENTLY AVAILABLE ONLINE VERSION OF MINECRAFT JAVA SERVER (works as at 202407)
import requests
from bs4 import BeautifulSoup

# URL of the Minecraft server download page
URL = "https://www.minecraft.net/en-us/download/server"

# Headers to mimic a real browser request
headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
}

# Fetch the HTML content of the page
response = requests.get(URL, headers=headers)

# Check if the request was successful
if response.status_code == 200:
    html_content = response.text
    # Parse the HTML content
    soup = BeautifulSoup(html_content, 'html.parser')
    # Find the link that contains the Minecraft server jar
    link = soup.find('a', href=True, string=lambda t: t and 'minecraft_server' in t)
    if link:
        # Extract the version number from the text
        link_text = link.text
        version = link_text.split('minecraft_server.')[1].split('.jar')[0]
        print(f"{version}")
    else:
        print("Fail-Minecraft server download link not found.")
else:
    print(f"Fail-Webpage download code: {response.status_code}")
